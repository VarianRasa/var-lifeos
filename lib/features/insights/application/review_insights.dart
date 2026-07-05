/// Review and journaling cadence insights.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';

final class ReviewGap {
  const ReviewGap({
    required this.start,
    required this.end,
    required this.dayCount,
  });

  final DateTime start;
  final DateTime end;
  final int dayCount;
}

final class ReviewInsightSummary {
  const ReviewInsightSummary({
    required this.journalCount,
    required this.reviewCount,
    required this.lastReviewDate,
    required this.currentReflectionStreak,
    required this.longestReflectionStreak,
    required this.reviewGaps,
    required this.keywordBuckets,
    required this.hasReviewThisWeek,
  });

  final int journalCount;
  final int reviewCount;
  final DateTime? lastReviewDate;
  final int currentReflectionStreak;
  final int longestReflectionStreak;
  final List<ReviewGap> reviewGaps;
  final Map<String, int> keywordBuckets;
  final bool hasReviewThisWeek;
}

ReviewInsightSummary buildReviewInsightSummary({
  required DateTime start,
  required DateTime end,
  required DateTime today,
  required Iterable<MindmapNode> nodes,
}) {
  final normalizedStart = start.dateOnly;
  final normalizedEnd = end.dateOnly;
  final normalizedToday = today.dateOnly;
  final journalDays = <DateTime>{};
  final reviewDays = <DateTime>{};
  final keywords = <String, int>{};
  var journalCount = 0;
  var reviewCount = 0;

  for (final node in nodes) {
    if (node.isArchived ||
        !_isInRange(node.day, normalizedStart, normalizedEnd)) {
      continue;
    }
    if (!_isJournalLike(node)) continue;
    journalCount++;
    journalDays.add(node.day.dateOnly);
    _addKeywords(keywords, node);
    if (_isReview(node)) {
      reviewCount++;
      reviewDays.add(node.day.dateOnly);
    }
  }

  final sortedReviewDays = reviewDays.toList()..sort();
  final sortedJournalDays = journalDays.toList()..sort();
  final gaps = _reviewGaps(sortedReviewDays, normalizedStart, normalizedEnd);
  final weekStart = normalizedToday.startOfWeek;

  return ReviewInsightSummary(
    journalCount: journalCount,
    reviewCount: reviewCount,
    lastReviewDate: sortedReviewDays.isEmpty ? null : sortedReviewDays.last,
    currentReflectionStreak: _currentStreak(sortedJournalDays, normalizedToday),
    longestReflectionStreak: _longestStreak(sortedJournalDays),
    reviewGaps: List.unmodifiable(gaps),
    keywordBuckets: Map.unmodifiable(_topKeywords(keywords)),
    hasReviewThisWeek: sortedReviewDays.any(
      (day) => !day.isBefore(weekStart) && !day.isAfter(normalizedToday),
    ),
  );
}

bool isReviewNode(MindmapNode node) => _isReview(node);

List<ReviewGap> _reviewGaps(
  List<DateTime> reviewDays,
  DateTime start,
  DateTime end,
) {
  final gaps = <ReviewGap>[];
  var cursor = start;
  for (final reviewDay in reviewDays) {
    final gapEnd = reviewDay.addDays(-1);
    if (!gapEnd.isBefore(cursor)) {
      final dayCount = gapEnd.difference(cursor).inDays + 1;
      if (dayCount >= 7) {
        gaps.add(ReviewGap(start: cursor, end: gapEnd, dayCount: dayCount));
      }
    }
    cursor = reviewDay.addDays(1);
  }
  if (!end.isBefore(cursor)) {
    final dayCount = end.difference(cursor).inDays + 1;
    if (dayCount >= 7) {
      gaps.add(ReviewGap(start: cursor, end: end, dayCount: dayCount));
    }
  }
  return gaps;
}

int _currentStreak(List<DateTime> days, DateTime today) {
  final keys = days.map(dayKey).toSet();
  var cursor = keys.contains(dayKey(today)) ? today : today.addDays(-1);
  var streak = 0;
  while (keys.contains(dayKey(cursor))) {
    streak++;
    cursor = cursor.addDays(-1);
  }
  return streak;
}

int _longestStreak(List<DateTime> days) {
  if (days.isEmpty) return 0;
  var longest = 1;
  var current = 1;
  for (var index = 1; index < days.length; index++) {
    if (days[index].difference(days[index - 1]).inDays == 1) {
      current++;
    } else {
      if (current > longest) longest = current;
      current = 1;
    }
  }
  return current > longest ? current : longest;
}

bool _isJournalLike(MindmapNode node) {
  return node.type == NodeType.journal ||
      node.tags.contains('journal') ||
      _isReview(node);
}

bool _isReview(MindmapNode node) {
  final title = node.title.toLowerCase();
  final tags = node.tags.map((tag) => tag.toLowerCase()).toSet();
  final journal = _sectionData(node.data, 'journal');
  return node.type == NodeType.journal &&
          (title.contains('review') ||
              tags.contains('review') ||
              tags.contains('weekly-review') ||
              tags.contains('monthly-review') ||
              journal['isWeeklyReview'] == true ||
              journal['isMonthlyReview'] == true) ||
      tags.contains('review');
}

void _addKeywords(Map<String, int> counts, MindmapNode node) {
  for (final tag in node.tags) {
    final normalized = tag.trim().toLowerCase();
    if (normalized.isNotEmpty && !_stopWords.contains(normalized)) {
      counts[normalized] = (counts[normalized] ?? 0) + 1;
    }
  }
  final text = '${node.title} ${node.body}'.toLowerCase();
  for (final match in RegExp(r'[a-z0-9]{4,}').allMatches(text)) {
    final word = match.group(0);
    if (word == null || _stopWords.contains(word)) continue;
    counts[word] = (counts[word] ?? 0) + 1;
  }
}

Map<String, int> _topKeywords(Map<String, int> counts) {
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final countCompare = b.value.compareTo(a.value);
      if (countCompare != 0) return countCompare;
      return a.key.compareTo(b.key);
    });
  return {for (final entry in entries.take(6)) entry.key: entry.value};
}

bool _isInRange(DateTime day, DateTime start, DateTime end) {
  final value = day.dateOnly;
  return !value.isBefore(start) && !value.isAfter(end);
}

Map<String, Object?> _sectionData(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value is Map<String, Object?>) return value;
  if (value is Map<Object?, Object?>) return value.cast<String, Object?>();
  return const {};
}

const _stopWords = {
  'this',
  'that',
  'with',
  'from',
  'have',
  'review',
  'weekly',
  'monthly',
  'journal',
  'today',
};
