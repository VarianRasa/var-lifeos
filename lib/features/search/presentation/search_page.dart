import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/animated_empty_state.dart';
import '../../../shared/widgets/error_message.dart';
import '../application/search_providers.dart';
import '../domain/search_query.dart';
import '../domain/search_result.dart';
import 'search_filter_bar.dart';
import 'search_result_tile.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({this.initialQuery = '', super.key});

  final String initialQuery;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _controller;
  SearchFilters _filters = const SearchFilters();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = SearchQuery(text: _controller.text, filters: _filters);
    final results = ref.watch(searchResultsProvider(query));
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('global-search-query'),
                  controller: _controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Search everything',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) {
                    setState(() {});
                    final router = GoRouter.maybeOf(context);
                    if (router != null) {
                      unawaited(
                        router.replace(
                          Uri(
                            path: '/search',
                            queryParameters: value.trim().isEmpty
                                ? null
                                : {'q': value},
                          ).toString(),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
                SearchFilterBar(
                  filters: _filters,
                  onChanged: (value) => setState(() => _filters = value),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _SearchResults(
                    results: results,
                    queryText: _controller.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.results, required this.queryText});

  final AsyncValue<List<SearchResult>> results;
  final String queryText;

  @override
  Widget build(BuildContext context) => results.when(
    loading: () => Center(
      child: Semantics(
        key: const ValueKey('search-loading'),
        liveRegion: true,
        label: 'Searching',
        child: const CircularProgressIndicator(),
      ),
    ),
    error: (error, stackTrace) => const ErrorMessage(
      key: ValueKey('search-error'),
      title: 'Search unavailable',
      message: 'Search could not be completed. Try again.',
    ),
    data: (items) => items.isEmpty
        ? AnimatedEmptyState(
            key: const ValueKey('search-empty'),
            icon: Icons.search_off_outlined,
            label: queryText.trim().isEmpty
                ? 'Search your workspace'
                : 'No results for “${queryText.trim()}”',
            subtitle: 'Try fewer words or clear filters.',
          )
        : ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) => SearchResultTile(
              result: items[index],
              onTap: () => openSearchResult(context, items[index]),
            ),
          ),
  );
}

void openSearchResult(BuildContext context, SearchResult result) {
  final document = result.document;
  if (document.sourceKind.name == 'node' && document.date != null) {
    context.go(
      '/calendar/${document.date!.toIso8601String().substring(0, 10)}'
      '?highlight=${Uri.encodeQueryComponent(document.sourceId)}',
    );
    return;
  }
  if (document.boardId case final boardId?) {
    final workspace = document.workspaceId.split(':');
    if (workspace.length > 1) {
      context.go(
        Uri(
          pathSegments: [
            'workspaces',
            workspace.first,
            workspace.skip(1).join(':'),
          ],
          queryParameters: {'view': 'canvas', 'board': boardId},
        ).toString(),
      );
    }
  }
}
