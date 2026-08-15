/// Online author and quote discovery for Quote nodes.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/quote_catalog_providers.dart';
import '../../domain/mindmap_node.dart';
import '../../domain/node_type_payloads.dart';
import '../../domain/quote_catalog.dart';

final class QuoteDiscoveryPanel extends ConsumerStatefulWidget {
  const QuoteDiscoveryPanel({
    required this.node,
    required this.payload,
    required this.manualEditor,
    required this.onBodyChanged,
    required this.onPayloadChanged,
    super.key,
  });

  final MindmapNode node;
  final QuotePayload payload;
  final Widget manualEditor;
  final ValueChanged<String> onBodyChanged;
  final ValueChanged<QuotePayload> onPayloadChanged;

  @override
  ConsumerState<QuoteDiscoveryPanel> createState() =>
      _QuoteDiscoveryPanelState();
}

final class _QuoteDiscoveryPanelState
    extends ConsumerState<QuoteDiscoveryPanel> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  var _discover = false;
  var _loadingAuthors = false;
  var _loadingQuotes = false;
  String? _error;
  List<QuoteAuthor> _authors = const [];
  QuoteAuthor? _selectedAuthor;
  CatalogQuotePage? _quotePage;

  @override
  void initState() {
    super.initState();
    _discover = widget.node.body.contains('Quote text here');
    if (_discover) unawaited(_loadPopular());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  QuoteCatalogRepository get _catalog =>
      ref.read(quoteCatalogRepositoryProvider);

  Future<void> _loadPopular() async {
    setState(() {
      _loadingAuthors = true;
      _error = null;
      _selectedAuthor = null;
      _quotePage = null;
    });
    try {
      final authors = await _catalog.popularAuthors();
      if (mounted) setState(() => _authors = authors);
    } on QuoteCatalogException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loadingAuthors = false);
    }
  }

  void _search(String raw) {
    setState(() {});
    _debounce?.cancel();
    final query = raw.trim();
    if (query.length < 2) {
      if (query.isEmpty) unawaited(_loadPopular());
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _runSearch(query),
    );
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      _loadingAuthors = true;
      _error = null;
      _selectedAuthor = null;
      _quotePage = null;
    });
    try {
      final page = await _catalog.searchAuthors(query: query);
      if (mounted) setState(() => _authors = page.authors);
    } on QuoteCatalogException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loadingAuthors = false);
    }
  }

  void _clearSearch() {
    _searchController.clear();
    unawaited(_loadPopular());
  }

  Future<void> _selectAuthor(QuoteAuthor author, {int page = 1}) async {
    setState(() {
      _selectedAuthor = author;
      _loadingQuotes = true;
      _error = null;
    });
    try {
      final quotes = await _catalog.quotesByAuthor(
        authorSlug: author.slug,
        page: page,
      );
      if (mounted) setState(() => _quotePage = quotes);
    } on QuoteCatalogException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loadingQuotes = false);
    }
  }

  void _useQuote(CatalogQuote quote) {
    widget.onBodyChanged(quote.text);
    widget.onPayloadChanged(
      widget.payload.copyWith(
        author: quote.authorName,
        source: quote.provider,
        tags: quote.tags,
        remoteQuoteId: quote.id,
        quoteProvider: quote.provider,
        sourceUrl: quote.sourceUrl,
      ),
    );
    setState(() => _discover = false);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final catalogHeight = constraints.hasBoundedHeight
          ? (constraints.maxHeight - 200).clamp(220.0, 430.0)
          : 430.0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quote library',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Browse authors or keep writing your own quote.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: true,
                    icon: Icon(Icons.travel_explore_rounded),
                    label: Text('Discover'),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    icon: Icon(Icons.edit_outlined),
                    label: Text('Manual'),
                  ),
                ],
                selected: <bool>{_discover},
                onSelectionChanged: (value) {
                  setState(() => _discover = value.single);
                  if (_discover && _authors.isEmpty) unawaited(_loadPopular());
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!_discover)
            widget.manualEditor
          else
            _discoverView(context, catalogHeight: catalogHeight),
        ],
      );
    },
  );

  Widget _discoverView(BuildContext context, {required double catalogHeight}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey<String>('quote-author-search-field'),
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Search authors',
              hintText: 'Try Maya Angelou or Rumi',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey<String>('quote-author-search-clear'),
                      tooltip: 'Clear search',
                      onPressed: _clearSearch,
                      icon: const Icon(Icons.close_rounded),
                    ),
              isDense: true,
            ),
            onChanged: _search,
            onSubmitted: (value) {
              _debounce?.cancel();
              final query = value.trim();
              if (query.length >= 2) unawaited(_runSearch(query));
            },
          ),
          const SizedBox(height: 12),
          if (_selectedAuthor == null)
            Row(
              children: [
                Text(
                  _searchController.text.trim().length >= 2
                      ? 'Search results'
                      : 'Popular authors',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '${_authors.length} authors',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            )
          else
            _SelectedAuthorHeader(
              author: _selectedAuthor!,
              page: _quotePage?.page ?? 1,
              totalPages: _quotePage?.totalPages ?? 0,
              onBack: () => setState(() {
                _selectedAuthor = null;
                _quotePage = null;
                _error = null;
              }),
            ),
          const SizedBox(height: 8),
          SizedBox(
            key: const ValueKey<String>('quote-catalog-viewport'),
            height: catalogHeight,
            child: _catalogViewport(context),
          ),
        ],
      );

  Widget _catalogViewport(BuildContext context) {
    if (_error != null) {
      return _CatalogError(
        message: _error!,
        onRetry: _selectedAuthor == null
            ? _loadPopular
            : () => _selectAuthor(_selectedAuthor!),
        onManual: () => setState(() => _discover = false),
      );
    }
    if (_selectedAuthor == null) {
      if (_loadingAuthors) return const _AuthorSkeletonGrid();
      if (_authors.isEmpty) {
        return const _CatalogEmpty(
          icon: Icons.person_search_rounded,
          title: 'No authors found',
          message: 'Try a shorter name or check the spelling.',
        );
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 680
              ? 3
              : constraints.maxWidth >= 400
              ? 2
              : 1;
          return GridView.builder(
            key: const ValueKey<String>('quote-author-grid'),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: 92,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _authors.length,
            itemBuilder: (context, index) {
              final author = _authors[index];
              return _AuthorCard(
                author: author,
                onTap: () => _selectAuthor(author),
              );
            },
          );
        },
      );
    }
    if (_loadingQuotes) return const _QuoteSkeletonList();
    final page = _quotePage;
    if (page == null || page.quotes.isEmpty) {
      return _CatalogEmpty(
        icon: Icons.format_quote_rounded,
        title: 'No quotes found',
        message: 'No quotes are available for ${_selectedAuthor!.name}.',
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            key: const ValueKey<String>('quote-result-list'),
            itemCount: page.quotes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _QuoteResultCard(
              quote: page.quotes[index],
              onUse: () => _useQuote(page.quotes[index]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _QuotePagination(
          page: page.page,
          totalPages: page.totalPages,
          hasNextPage: page.hasNextPage,
          onPrevious: page.page <= 1
              ? null
              : () => _selectAuthor(_selectedAuthor!, page: page.page - 1),
          onNext: !page.hasNextPage
              ? null
              : () => _selectAuthor(_selectedAuthor!, page: page.page + 1),
        ),
      ],
    );
  }
}

final class _AuthorCard extends StatelessWidget {
  const _AuthorCard({required this.author, required this.onTap});
  final QuoteAuthor author;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${author.name}, ${author.quoteCount} quotes',
    child: Tooltip(
      message: author.name,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey<String>('quote-author-${author.slug}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  child: Text(_initials(author.name)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        author.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${author.quoteCount} quotes',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

final class _SelectedAuthorHeader extends StatelessWidget {
  const _SelectedAuthorHeader({
    required this.author,
    required this.page,
    required this.totalPages,
    required this.onBack,
  });
  final QuoteAuthor author;
  final int page;
  final int totalPages;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        key: const ValueKey<String>('quote-author-back'),
        tooltip: 'Back to authors',
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      CircleAvatar(radius: 17, child: Text(_initials(author.name))),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              author.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              '${author.quoteCount} quotes',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
      if (totalPages > 0)
        Text(
          'Page $page of $totalPages',
          style: Theme.of(context).textTheme.labelMedium,
        ),
    ],
  );
}

final class _QuoteResultCard extends StatelessWidget {
  const _QuoteResultCard({required this.quote, required this.onUse});
  final CatalogQuote quote;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.format_quote_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 6),
          Tooltip(
            message: quote.text,
            child: Text(
              quote.text,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(height: 1.45),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '— ${quote.authorName} · ${quote.provider}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              FilledButton.icon(
                key: ValueKey<String>('quote-use-${quote.id}'),
                onPressed: onUse,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Use this quote'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

final class _QuotePagination extends StatelessWidget {
  const _QuotePagination({
    required this.page,
    required this.totalPages,
    required this.hasNextPage,
    required this.onPrevious,
    required this.onNext,
  });
  final int page;
  final int totalPages;
  final bool hasNextPage;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      OutlinedButton.icon(
        key: const ValueKey<String>('quote-previous-page'),
        onPressed: onPrevious,
        icon: const Icon(Icons.chevron_left_rounded),
        label: const Text('Previous'),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text('Page $page of $totalPages'),
      ),
      OutlinedButton.icon(
        key: const ValueKey<String>('quote-next-page'),
        onPressed: hasNextPage ? onNext : null,
        iconAlignment: IconAlignment.end,
        icon: const Icon(Icons.chevron_right_rounded),
        label: const Text('Next'),
      ),
    ],
  );
}

final class _CatalogError extends StatelessWidget {
  const _CatalogError({
    required this.message,
    required this.onRetry,
    required this.onManual,
  });
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 34,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(height: 10),
              Text(
                'Quote library unavailable',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    key: const ValueKey<String>('quote-discovery-retry'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                  TextButton(
                    onPressed: onManual,
                    child: const Text('Write manually'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _CatalogEmpty extends StatelessWidget {
  const _CatalogEmpty({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 10),
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );
}

final class _AuthorSkeletonGrid extends StatelessWidget {
  const _AuthorSkeletonGrid();

  @override
  Widget build(BuildContext context) => GridView.builder(
    key: const ValueKey<String>('quote-author-skeleton'),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisExtent: 92,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
    ),
    itemCount: 6,
    itemBuilder: (context, index) => const _SkeletonCard(height: 92),
  );
}

final class _QuoteSkeletonList extends StatelessWidget {
  const _QuoteSkeletonList();

  @override
  Widget build(BuildContext context) => ListView.separated(
    key: const ValueKey<String>('quote-result-skeleton'),
    itemCount: 3,
    separatorBuilder: (_, _) => const SizedBox(height: 10),
    itemBuilder: (_, _) => const _SkeletonCard(height: 132),
  );
}

final class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
  );
}

String _initials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
  return '${words.first[0]}${words.last[0]}'.toUpperCase();
}
