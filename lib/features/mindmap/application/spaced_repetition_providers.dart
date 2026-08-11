/// Application providers for Spaced Repetition (Flashcards).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/mindmap_node.dart';
import '../domain/spaced_repetition.dart';
import 'mindmap_providers.dart';

/// Provider returning all due flashcard nodes across the entire repository.
final dueFlashcardsProvider = Provider<List<MindmapNode>>((ref) {
  final allNodesAsync = ref.watch(allMindmapNodesProvider);
  final nodes = allNodesAsync.valueOrNull ?? const [];

  return nodes
      .where(isFlashcardNode)
      .where((node) => !node.isArchived)
      .where((node) => getFlashcardState(node).isDueToday)
      .toList();
});

/// Count of flashcards due for review today.
final dueFlashcardsCountProvider = Provider<int>((ref) {
  return ref.watch(dueFlashcardsProvider).length;
});
