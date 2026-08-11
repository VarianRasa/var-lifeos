/// Quote Collector & SM-2 Flashcard converter helpers (Readwise style).
library;

import '../../../core/constants/app_constants.dart';
import 'mindmap_node.dart';
import 'spaced_repetition.dart';

bool isQuoteNode(MindmapNode node) {
  return node.type == NodeType.quote || node.tags.contains('quote');
}

/// Converts a Quote node into a Spaced Repetition Flashcard node.
MindmapNode convertQuoteToFlashcard(MindmapNode node, {DateTime? now}) {
  final initialSpacedState = SpacedRepetitionItem.initial();
  final author =
      (node.data['quote'] as Map?)?['author'] as String? ?? 'Unknown Author';

  return node.copyWith(
    data: {
      ...node.data,
      'flashcard': initialSpacedState.toJson(),
      'answer': '— $author',
    },
    tags: node.tags.contains('flashcard')
        ? node.tags
        : [...node.tags, 'flashcard', 'quote-card'],
    updatedAt: now ?? DateTime.now(),
  );
}
