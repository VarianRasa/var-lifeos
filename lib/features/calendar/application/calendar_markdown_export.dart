/// Markdown export for calendar summaries.
library;

import 'package:intl/intl.dart';

import '../../mindmap/domain/mindmap_node.dart';
import 'calendar_day_summary.dart';
import 'calendar_planning_engine.dart';
import 'calendar_range_summary.dart';

String exportCalendarDayMarkdown({
  required CalendarDaySummary summary,
  required Iterable<MindmapNode> nodes,
  Iterable<CalendarPlanningSuggestion> suggestions = const [],
}) {
  final buffer = StringBuffer()
    ..writeln('# ${DateFormat('EEEE, MMM d, y').format(summary.day)}')
    ..writeln()
    ..writeln('- Open tasks: ${summary.openTasks}')
    ..writeln('- Completed tasks: ${summary.completedTasks}')
    ..writeln('- Overdue tasks: ${summary.overdueTasks}')
    ..writeln('- Focus minutes: ${summary.focusMinutes}')
    ..writeln('- Habits: ${summary.completedHabits}/${summary.habitCount}')
    ..writeln('- Journal/review: ${summary.hasJournalOrReview ? 'yes' : 'no'}')
    ..writeln();
  _writeNodeSection(
    buffer,
    'Completed tasks',
    nodes.where((node) => node.isDone),
  );
  _writeNodeSection(buffer, 'Open tasks', nodes.where((node) => !node.isDone));
  _writeSuggestions(buffer, suggestions);
  return buffer.toString().trimRight();
}

String exportCalendarRangeMarkdown({
  required CalendarRangeSummary summary,
  Iterable<CalendarPlanningSuggestion> suggestions = const [],
  String title = 'Calendar summary',
}) {
  final buffer = StringBuffer()
    ..writeln('# $title')
    ..writeln()
    ..writeln('- Total tasks: ${summary.totalTasks}')
    ..writeln('- Completed: ${summary.completedTasks}')
    ..writeln('- Overdue: ${summary.overdueTasks}')
    ..writeln('- Focus minutes: ${summary.focusMinutes}')
    ..writeln('- Journals/reviews: ${summary.journals}')
    ..writeln('- Habit completions: ${summary.habitCompletions}')
    ..writeln();
  _writeSuggestions(buffer, suggestions);
  return buffer.toString().trimRight();
}

String exportCalendarMonthMarkdown({
  required DateTime month,
  required Iterable<MindmapNode> nodes,
  Iterable<CalendarPlanningSuggestion> suggestions = const [],
}) {
  final firstDay = DateTime(month.year, month.month);
  final nextMonth = DateTime(month.year, month.month + 1);
  final monthNodes = nodes
      .where(
        (node) => !node.day.isBefore(firstDay) && node.day.isBefore(nextMonth),
      )
      .toList(growable: false);
  final summary = buildCalendarRangeSummary(
    start: firstDay,
    end: nextMonth.subtract(const Duration(days: 1)),
    nodes: monthNodes,
  );
  final buffer = StringBuffer(
    exportCalendarRangeMarkdown(
      summary: summary,
      suggestions: suggestions,
      title: DateFormat('MMMM y').format(firstDay),
    ),
  )..writeln();
  _writeNodeSection(
    buffer,
    'Overdue tasks',
    monthNodes.where((node) => !node.isDone && node.dueDate != null),
  );
  return buffer.toString().trimRight();
}

void _writeNodeSection(
  StringBuffer buffer,
  String title,
  Iterable<MindmapNode> nodes,
) {
  final list = nodes.toList(growable: false);
  if (list.isEmpty) return;
  buffer
    ..writeln('## $title')
    ..writeln();
  for (final node in list) {
    buffer.writeln('- ${node.title}');
  }
  buffer.writeln();
}

void _writeSuggestions(
  StringBuffer buffer,
  Iterable<CalendarPlanningSuggestion> suggestions,
) {
  final list = suggestions.toList(growable: false);
  if (list.isEmpty) return;
  buffer
    ..writeln('## Planning suggestions')
    ..writeln();
  for (final suggestion in list) {
    buffer.writeln('- **${suggestion.title}** — ${suggestion.message}');
  }
}
