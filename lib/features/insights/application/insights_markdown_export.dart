/// Markdown report export helpers for Insights.
library;

import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';
import 'context_health.dart';
import 'focus_insights.dart';
import 'goal_insights.dart';
import 'habit_insights.dart';
import 'insight_recommendations.dart';
import 'insight_risk_engine.dart';
import 'insights_summary.dart';
import 'insights_trends.dart';
import 'review_insights.dart';

final class InsightsMarkdownReportInput {
  const InsightsMarkdownReportInput({
    required this.generatedAt,
    required this.rangeStart,
    required this.rangeEnd,
    required this.nodes,
    required this.missionSummaries,
    required this.completionTrend,
    required this.risks,
    required this.recommendations,
    required this.contextHealth,
    required this.focusSummary,
    required this.habitSummary,
    required this.reviewSummary,
    required this.goalSummary,
    this.scopeLabel = 'Current dashboard',
  });

  final DateTime generatedAt;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final Iterable<MindmapNode> nodes;
  final List<InsightsSummary> missionSummaries;
  final InsightTrendSeries completionTrend;
  final List<InsightRisk> risks;
  final List<InsightRecommendation> recommendations;
  final ContextHealthSummary contextHealth;
  final FocusInsightSummary focusSummary;
  final HabitInsightSummary habitSummary;
  final ReviewInsightSummary reviewSummary;
  final GoalInsightSummary goalSummary;
  final String scopeLabel;
}

String buildInsightsMarkdownReport(InsightsMarkdownReportInput input) {
  final nodes = input.nodes.where((node) => !node.isArchived).toList();
  final completedTasks = _completedTasks(nodes);
  final overdueTasks = _overdueTasks(nodes, input.generatedAt.dateOnly);
  final summary = _summaryForRange(input);
  final buffer = StringBuffer()
    ..writeln('# Var insights report')
    ..writeln()
    ..writeln('- Scope: ${input.scopeLabel}')
    ..writeln('- Range: ${_date(input.rangeStart)} → ${_date(input.rangeEnd)}')
    ..writeln('- Generated: ${_dateTime(input.generatedAt)}')
    ..writeln()
    ..writeln('## Summary metrics')
    ..writeln()
    ..writeln('| Metric | Value | Δ previous |')
    ..writeln('| --- | ---: | ---: |');

  if (summary == null) {
    buffer
      ..writeln('| Open tasks | ${_openTasks(nodes)} | — |')
      ..writeln('| Completed tasks | ${completedTasks.length} | — |')
      ..writeln('| Overdue tasks | ${overdueTasks.length} | — |')
      ..writeln('| Focus minutes | ${input.focusSummary.totalMinutes} | — |')
      ..writeln(
        '| Habit completion | ${_percent(input.habitSummary.completionRate)} | — |',
      )
      ..writeln('| Reviews | ${input.reviewSummary.reviewCount} | — |');
  } else {
    buffer
      ..writeln(
        '| Open tasks | ${summary.current.openTasks} | ${_signed(summary.openTaskDelta)} |',
      )
      ..writeln(
        '| Completed tasks | ${summary.current.completedTasks} | ${_signed(summary.completedTaskDelta)} |',
      )
      ..writeln(
        '| Overdue tasks | ${summary.current.overdueTasks} | ${_signed(summary.overdueTaskDelta)} |',
      )
      ..writeln(
        '| High-priority open | ${summary.current.highPriorityOpenTasks} | ${_signed(summary.highPriorityOpenTaskDelta)} |',
      )
      ..writeln(
        '| Focus minutes | ${summary.current.focusMinutes} | ${_signed(summary.focusMinuteDelta)} |',
      )
      ..writeln(
        '| Habit completion | ${_percent(summary.current.habitCompletionRate)} | ${_signedPercent(summary.habitCompletionDelta)} |',
      )
      ..writeln(
        '| Reviews | ${summary.current.reviewCount} | ${_signed(summary.reviewCountDelta)} |',
      );
  }

  buffer
    ..writeln()
    ..writeln('## Trend highlights')
    ..writeln()
    ..writeln(
      '- Completion: ${_trend(input.completionTrend.completionDirection)}',
    )
    ..writeln(
      '- Open workload: ${_trend(input.completionTrend.openWorkDirection)}',
    )
    ..writeln('- Overdue: ${_trend(input.completionTrend.overdueDirection)}')
    ..writeln(
      '- High priority: ${_trend(input.completionTrend.highPriorityDirection)}',
    )
    ..writeln()
    ..writeln('## Risks')
    ..writeln();

  _writeBullets(
    buffer,
    input.risks
        .take(8)
        .map(
          (risk) =>
              '**${risk.title}** (${_riskSeverity(risk.severity)}): ${risk.message}',
        ),
    empty: 'No active risks.',
  );

  buffer
    ..writeln()
    ..writeln('## Recommendations')
    ..writeln();

  _writeBullets(
    buffer,
    input.recommendations
        .take(8)
        .map((item) => '**${item.title}**: ${item.message}'),
    empty: 'No recommended actions.',
  );

  buffer
    ..writeln()
    ..writeln('## Completed tasks')
    ..writeln();
  _writeNodeBullets(
    buffer,
    completedTasks.take(12),
    empty: 'No completed tasks.',
  );

  buffer
    ..writeln()
    ..writeln('## Overdue tasks')
    ..writeln();
  _writeNodeBullets(buffer, overdueTasks.take(12), empty: 'No overdue tasks.');

  buffer
    ..writeln()
    ..writeln('## Focus, habits, reviews')
    ..writeln()
    ..writeln('- Focus minutes: ${input.focusSummary.totalMinutes}')
    ..writeln(
      '- Best focus day: ${_optionalDate(input.focusSummary.bestFocusDay)}',
    )
    ..writeln(
      '- Habit completion: ${_percent(input.habitSummary.completionRate)}',
    )
    ..writeln('- Missed habits: ${input.habitSummary.missedHabits.length}')
    ..writeln('- Reviews: ${input.reviewSummary.reviewCount}')
    ..writeln(
      '- Last review: ${_optionalDate(input.reviewSummary.lastReviewDate)}',
    )
    ..writeln()
    ..writeln('## Project / area summary')
    ..writeln();

  _writeBullets(
    buffer,
    input.contextHealth.items
        .take(10)
        .map(
          (item) =>
              '${item.isProject ? 'Project' : 'Area'} ${item.name}: ${item.openTasks} open, ${item.completedTasks} done, ${item.overdueTasks} overdue, ${item.highPriorityOpenTasks} high priority (${_contextStatus(item.status)})',
        ),
    empty: 'No project or area activity.',
  );

  buffer
    ..writeln()
    ..writeln('## Goal status')
    ..writeln()
    ..writeln('- Goals: ${input.goalSummary.items.length}')
    ..writeln('- Stalled goals: ${input.goalSummary.stalledGoals.length}')
    ..writeln(
      '- Recently progressed: ${input.goalSummary.recentlyProgressedGoals.length}',
    );

  return buffer.toString().trimRight();
}

InsightsSummary? _summaryForRange(InsightsMarkdownReportInput input) {
  if (input.missionSummaries.isEmpty) return null;
  final days =
      input.rangeEnd.dateOnly.difference(input.rangeStart.dateOnly).inDays + 1;
  for (final summary in input.missionSummaries) {
    if (summary.window.dayCount == days) return summary;
  }
  return input.missionSummaries.first;
}

List<MindmapNode> _completedTasks(List<MindmapNode> nodes) {
  return nodes
      .where((node) => node.type == NodeType.task && _isComplete(node))
      .toList()
    ..sort(_nodeSort);
}

List<MindmapNode> _overdueTasks(List<MindmapNode> nodes, DateTime today) {
  return nodes
      .where(
        (node) =>
            node.type == NodeType.task &&
            !_isComplete(node) &&
            node.dueDate != null &&
            node.dueDate!.dateOnly.isBefore(today),
      )
      .toList()
    ..sort(_nodeSort);
}

int _openTasks(List<MindmapNode> nodes) {
  return nodes
      .where((node) => node.type == NodeType.task && !_isComplete(node))
      .length;
}

bool _isComplete(MindmapNode node) {
  return node.isDone || node.status == NodeStatus.done || node.progress >= 1;
}

int _nodeSort(MindmapNode a, MindmapNode b) {
  final dayCompare = a.day.compareTo(b.day);
  if (dayCompare != 0) return dayCompare;
  return a.title.compareTo(b.title);
}

void _writeBullets(
  StringBuffer buffer,
  Iterable<String> items, {
  required String empty,
}) {
  final values = items.toList(growable: false);
  if (values.isEmpty) {
    buffer.writeln('- $empty');
    return;
  }
  for (final item in values) {
    buffer.writeln('- $item');
  }
}

void _writeNodeBullets(
  StringBuffer buffer,
  Iterable<MindmapNode> nodes, {
  required String empty,
}) {
  final values = nodes.toList(growable: false);
  if (values.isEmpty) {
    buffer.writeln('- $empty');
    return;
  }
  for (final node in values) {
    final context = [
      if (node.project.isNotEmpty) node.project,
      if (node.area.isNotEmpty) node.area,
      ...node.tags.map((tag) => '#$tag'),
    ].join(' · ');
    buffer.writeln(
      '- ${node.title} (${_date(node.day)}${context.isEmpty ? '' : ' · $context'})',
    );
  }
}

String _date(DateTime value) => DateFormat('yyyy-MM-dd').format(value.dateOnly);

String _dateTime(DateTime value) =>
    DateFormat('yyyy-MM-dd HH:mm').format(value);

String _optionalDate(DateTime? value) => value == null ? '—' : _date(value);

String _signed(int value) => value > 0 ? '+$value' : '$value';

String _percent(double value) => '${(value.clamp(0, 1) * 100).round()}%';

String _signedPercent(double value) {
  final percent = (value * 100).round();
  return percent > 0 ? '+$percent%' : '$percent%';
}

String _trend(InsightTrendDirection direction) {
  switch (direction) {
    case InsightTrendDirection.up:
      return 'up';
    case InsightTrendDirection.down:
      return 'down';
    case InsightTrendDirection.flat:
      return 'flat';
    case InsightTrendDirection.volatile:
      return 'volatile';
  }
}

String _riskSeverity(InsightRiskSeverity severity) {
  switch (severity) {
    case InsightRiskSeverity.info:
      return 'info';
    case InsightRiskSeverity.watch:
      return 'watch';
    case InsightRiskSeverity.high:
      return 'high';
    case InsightRiskSeverity.critical:
      return 'critical';
  }
}

String _contextStatus(ContextHealthStatus status) {
  switch (status) {
    case ContextHealthStatus.good:
      return 'good';
    case ContextHealthStatus.watch:
      return 'watch';
    case ContextHealthStatus.stale:
      return 'stale';
    case ContextHealthStatus.critical:
      return 'critical';
  }
}
