import 'package:flutter/material.dart';

import '../domain/search_document.dart';
import '../domain/search_result.dart';

class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    required this.result,
    required this.onTap,
    super.key,
  });

  final SearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final document = result.document;
    return Card(
      child: ListTile(
        key: ValueKey('search-result-${document.id}'),
        title: Text(document.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(document.snippet),
            Text(_extractionLabel(document.extractionState)),
          ],
        ),
        trailing: Text(document.sourceKind.name),
        onTap: onTap,
      ),
    );
  }
}

String _extractionLabel(SearchExtractionState state) => switch (state) {
  SearchExtractionState.queued => 'Queued',
  SearchExtractionState.processing => 'Processing',
  SearchExtractionState.ready => 'Ready',
  SearchExtractionState.partial => 'Partial',
  SearchExtractionState.failed => 'Failed',
};
