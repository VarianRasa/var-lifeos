import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/insights/application/review_insights.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('isReviewNode detects review metadata and tags', () {
    final day = DateTime(2026, 7, 10);
    expect(
      isReviewNode(
        MindmapNode.create(
          id: 'weekly',
          type: NodeType.journal,
          title: 'Weekly notes',
          day: day,
          data: const {
            'journal': {'isWeeklyReview': true},
          },
        ),
      ),
      isTrue,
    );
    expect(
      isReviewNode(
        MindmapNode.create(
          id: 'tagged',
          type: NodeType.note,
          title: 'Retro',
          day: day,
          tags: const ['review'],
        ),
      ),
      isTrue,
    );
  });

  test('buildReviewInsightSummary counts cadence and gaps', () {
    final today = DateTime(2026, 7, 10);
    final nodes = [
      MindmapNode.create(
        id: 'j1',
        type: NodeType.journal,
        title: 'Energy reflection',
        body: 'Launch energy was high',
        day: today.addDays(-1),
        tags: const ['energy'],
      ),
      MindmapNode.create(
        id: 'j2',
        type: NodeType.journal,
        title: 'Weekly review',
        body: 'Launch review and risks',
        day: today,
        tags: const ['weekly-review', 'launch'],
        data: const {
          'journal': {'isWeeklyReview': true},
        },
      ),
      MindmapNode.create(
        id: 'old-review',
        type: NodeType.journal,
        title: 'Monthly review',
        day: today.addDays(-14),
        data: const {
          'journal': {'isMonthlyReview': true},
        },
      ),
    ];

    final summary = buildReviewInsightSummary(
      start: today.addDays(-14),
      end: today,
      today: today,
      nodes: nodes,
    );

    expect(summary.journalCount, 3);
    expect(summary.reviewCount, 2);
    expect(summary.lastReviewDate, today);
    expect(summary.hasReviewThisWeek, isTrue);
    expect(summary.currentReflectionStreak, 2);
    expect(summary.longestReflectionStreak, 2);
    expect(summary.reviewGaps.single.dayCount, 13);
    expect(summary.keywordBuckets['launch'], 3);
  });

  test('buildReviewInsightSummary reports missing weekly review', () {
    final today = DateTime(2026, 7, 10);
    final summary = buildReviewInsightSummary(
      start: today.startOfWeek,
      end: today,
      today: today,
      nodes: [
        MindmapNode.create(
          id: 'journal',
          type: NodeType.journal,
          title: 'Daily reflection',
          day: today,
        ),
      ],
    );

    expect(summary.hasReviewThisWeek, isFalse);
    expect(summary.reviewCount, 0);
  });
}
