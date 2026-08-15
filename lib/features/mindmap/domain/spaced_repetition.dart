/// Spaced Repetition domain engine using SuperMemo-2 (SM-2) algorithm.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import 'mindmap_node.dart';

/// Rating quality for SuperMemo-2 response (0 to 5).
enum FlashcardRating {
  blackout(0, 'Complete Blackout', 'Again'),
  incorrect(1, 'Incorrect Response', 'Hard'),
  wrongRemembered(2, 'Wrong, Easy to Recall', 'Hard'),
  correctDifficult(3, 'Correct with Effort', 'Good'),
  correctHesitation(4, 'Correct after Hesitation', 'Good'),
  perfect(5, 'Perfect Response', 'Easy');

  const FlashcardRating(this.score, this.description, this.label);
  final int score;
  final String description;
  final String label;
}

/// State of a flashcard item under SM-2 algorithm.
final class SpacedRepetitionItem {
  const SpacedRepetitionItem({
    required this.repetitions,
    required this.intervalDays,
    required this.easeFactor,
    required this.nextReviewDate,
    this.lastReviewedAt,
    this.history = const [],
  });

  factory SpacedRepetitionItem.initial() {
    return SpacedRepetitionItem(
      repetitions: 0,
      intervalDays: 1,
      easeFactor: 2.5,
      nextReviewDate: DateTime.now().dateOnly,
    );
  }

  factory SpacedRepetitionItem.fromJson(Map<String, Object?> json) {
    return SpacedRepetitionItem(
      repetitions: (json['repetitions'] as num?)?.toInt() ?? 0,
      intervalDays: (json['intervalDays'] as num?)?.toInt() ?? 1,
      easeFactor: (json['easeFactor'] as num?)?.toDouble() ?? 2.5,
      nextReviewDate:
          DateTime.tryParse(
            json['nextReviewDate'] as String? ?? '',
          )?.dateOnly ??
          DateTime.now().dateOnly,
      lastReviewedAt: DateTime.tryParse(
        json['lastReviewedAt'] as String? ?? '',
      ),
      history: [
        if (json['history'] is List)
          for (final item in json['history'] as List)
            if (item is Map) item.cast<String, Object?>(),
      ],
    );
  }

  final int repetitions;
  final int intervalDays;
  final double easeFactor;
  final DateTime nextReviewDate;
  final DateTime? lastReviewedAt;
  final List<Map<String, Object?>> history;

  Map<String, Object?> toJson() {
    return {
      'repetitions': repetitions,
      'intervalDays': intervalDays,
      'easeFactor': easeFactor,
      'nextReviewDate': dayKey(nextReviewDate),
      if (lastReviewedAt != null)
        'lastReviewedAt': lastReviewedAt!.toIso8601String(),
      'history': history,
    };
  }

  bool get isDueToday {
    final today = DateTime.now().dateOnly;
    return !nextReviewDate.isAfter(today);
  }

  /// Calculates next state using SM-2 algorithm based on user rating.
  SpacedRepetitionItem answer(FlashcardRating rating, {DateTime? now}) {
    final reviewTime = now ?? DateTime.now();
    final q = rating.score;

    int nextRepetitions;
    int nextInterval;

    if (q >= 3) {
      if (repetitions == 0) {
        nextInterval = 1;
      } else if (repetitions == 1) {
        nextInterval = 6;
      } else {
        nextInterval = (intervalDays * easeFactor).round();
      }
      nextRepetitions = repetitions + 1;
    } else {
      nextRepetitions = 0;
      nextInterval = 1;
    }

    // New EF = EF + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
    double nextEaseFactor =
        easeFactor + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02));
    if (nextEaseFactor < 1.3) {
      nextEaseFactor = 1.3;
    }

    final nextReview = reviewTime.dateOnly.add(Duration(days: nextInterval));

    final newHistoryEntry = {
      'rating': q,
      'reviewedAt': reviewTime.toIso8601String(),
      'interval': nextInterval,
      'easeFactor': nextEaseFactor,
    };

    return SpacedRepetitionItem(
      repetitions: nextRepetitions,
      intervalDays: nextInterval,
      easeFactor: nextEaseFactor,
      nextReviewDate: nextReview,
      lastReviewedAt: reviewTime,
      history: [...history, newHistoryEntry],
    );
  }
}

/// Helper methods for attaching/reading flashcards on MindmapNode.
bool isFlashcardNode(MindmapNode node) {
  if (node.type == NodeType.question ||
      node.type == NodeType.resource ||
      node.type == NodeType.note) {
    return node.data.containsKey('flashcard') ||
        node.tags.contains('flashcard');
  }
  return node.tags.contains('flashcard') || node.data.containsKey('flashcard');
}

SpacedRepetitionItem getFlashcardState(MindmapNode node) {
  final section = node.data['flashcard'];
  if (section is Map) {
    return SpacedRepetitionItem.fromJson(section.cast<String, Object?>());
  }
  return SpacedRepetitionItem.initial();
}

MindmapNode updateFlashcardState(
  MindmapNode node,
  SpacedRepetitionItem cardState, {
  DateTime? now,
}) {
  return node.copyWith(
    data: {...node.data, 'flashcard': cardState.toJson()},
    tags: node.tags.contains('flashcard')
        ? node.tags
        : [...node.tags, 'flashcard'],
    updatedAt: now ?? DateTime.now(),
  );
}
