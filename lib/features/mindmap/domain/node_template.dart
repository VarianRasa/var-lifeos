/// Reusable node templates for fast capture and richer workflows.
library;

import '../../../core/constants/app_constants.dart';
import 'kanban_board.dart';
import 'mindmap_node.dart';

final class NodeTemplate {
  const NodeTemplate({
    required this.id,
    required this.label,
    required this.type,
    required this.title,
    this.body = '',
    this.status = NodeStatus.open,
    this.priority = NodePriority.none,
    this.project = '',
    this.area = '',
    this.tags = const [],
    this.progress = 0,
    this.checklist = const [],
    this.data = const {},
  });

  final String id;
  final String label;
  final NodeType type;
  final String title;
  final String body;
  final NodeStatus status;
  final NodePriority priority;
  final String project;
  final String area;
  final List<String> tags;
  final double progress;
  final List<String> checklist;
  final Map<String, Object?> data;
}

final defaultNodeTemplates = List<NodeTemplate>.unmodifiable([
  const NodeTemplate(
    id: 'daily-plan',
    label: 'Daily plan',
    type: NodeType.plan,
    title: 'Daily plan',
    body: 'Choose outcomes, sequence the day, and leave room for review.',
    area: 'Work',
    tags: ['daily', 'plan'],
    data: {
      'plan': {
        'steps': ['Choose top outcomes', 'Sequence deep work', 'Review'],
      },
    },
  ),
  const NodeTemplate(
    id: 'daily-journal',
    label: 'Daily journal',
    type: NodeType.journal,
    title: 'Daily journal',
    body: 'Capture mood, energy, gratitude, and one short reflection.',
    area: 'Mind',
    tags: ['journal'],
    data: {
      'journal': {
        'mood': 0,
        'energy': 0,
        'prompt': 'What mattered today?',
        'gratitude': <String>[],
        'isWeeklyReview': false,
      },
    },
  ),
  const NodeTemplate(
    id: 'weekly-review',
    label: 'Weekly review',
    type: NodeType.journal,
    title: 'Weekly review',
    body: 'Review wins, stuck points, patterns, and the next week.',
    area: 'Mind',
    tags: ['review', 'weekly'],
    data: {
      'journal': {
        'mood': 0,
        'energy': 0,
        'prompt': 'What patterns showed up this week?',
        'gratitude': <String>[],
        'isWeeklyReview': true,
      },
    },
  ),
  const NodeTemplate(
    id: 'monthly-review',
    label: 'Monthly review',
    type: NodeType.journal,
    title: 'Monthly review',
    body: 'Review themes, commitments, wins, and next month direction.',
    area: 'Mind',
    tags: ['review', 'monthly'],
    data: {
      'journal': {
        'mood': 0,
        'energy': 0,
        'prompt': 'What changed this month?',
        'gratitude': <String>[],
        'isWeeklyReview': false,
        'isMonthlyReview': true,
      },
    },
  ),
  const NodeTemplate(
    id: 'workout-habit',
    label: 'Workout habit',
    type: NodeType.habit,
    title: 'Workout',
    body: 'Move the body and record the completion.',
    area: 'Health',
    tags: ['health'],
    data: {
      'habit': {
        'recurrence': 'daily',
        'target': '30 min',
        'completions': <String>[],
      },
    },
  ),
  const NodeTemplate(
    id: 'goal-tracker',
    label: 'Goal tracker',
    type: NodeType.goal,
    title: 'Goal tracker',
    body: 'Track the outcome, milestones, and progress.',
    status: NodeStatus.planned,
    priority: NodePriority.medium,
    data: {
      'goal': {
        'milestones': ['Define outcome', 'Ship first version', 'Review result'],
        'completedMilestones': <String>[],
      },
    },
  ),
  NodeTemplate(
    id: 'sprint-board',
    label: 'Sprint board',
    type: NodeType.kanban,
    title: 'Sprint board',
    body: 'Move work from todo to doing to done.',
    area: 'Work',
    tags: const ['sprint'],
    data: {
      'kanban': const KanbanBoard(
        cards: [
          KanbanCard(id: 'template-scope', title: 'Scope'),
          KanbanCard(
            id: 'template-build',
            title: 'Build',
            column: KanbanColumn.doing,
          ),
          KanbanCard(
            id: 'template-review',
            title: 'Review',
            column: KanbanColumn.done,
          ),
        ],
      ).toJson(),
    },
  ),
  const NodeTemplate(
    id: 'research-note',
    label: 'Research note',
    type: NodeType.note,
    title: 'Research note',
    body: 'Question, source, key points, and next action.',
    tags: ['research'],
    data: {
      'note': {'source': ''},
    },
  ),
  const NodeTemplate(
    id: 'link-inbox',
    label: 'Link inbox',
    type: NodeType.link,
    title: 'Link inbox',
    body: 'Save a URL and decide later where it belongs.',
    tags: ['inbox'],
    data: {
      'link': {'url': ''},
    },
  ),
  const NodeTemplate(
    id: 'event',
    label: 'Event',
    type: NodeType.task,
    title: 'Event',
    body: 'Scheduled calendar event.',
    data: {
      'calendar_kind': 'event',
      'time_block': {'startTime': '09:00', 'endTime': '10:00'},
    },
  ),
  const NodeTemplate(
    id: 'reminder',
    label: 'Reminder',
    type: NodeType.task,
    title: 'Reminder',
    body: 'A prompt with a scheduled time.',
    data: {
      'calendar_kind': 'reminder',
      'time_block': {'startTime': '09:00', 'endTime': '09:15'},
    },
  ),
  const NodeTemplate(
    id: 'meeting-notes',
    label: 'Meeting notes',
    type: NodeType.note,
    title: 'Meeting notes',
    body: 'Agenda, decisions, action items.',
    tags: ['meeting'],
    data: {
      'calendar_kind': 'meeting',
      'time_block': {'startTime': '10:00', 'endTime': '11:00'},
    },
  ),
  const NodeTemplate(
    id: 'decision-log',
    label: 'Decision log',
    type: NodeType.note,
    title: 'Decision log',
    body: 'Option picked and why.',
    tags: ['decision'],
    data: {'calendar_kind': 'decision'},
  ),
  const NodeTemplate(
    id: 'metric-tracker',
    label: 'Metric tracker',
    type: NodeType.task,
    title: 'Metric tracker',
    body: 'Track a numeric value for this day.',
    tags: ['metric'],
    data: {
      'calendar_kind': 'metric',
      'metric': {'value': '', 'unit': ''},
    },
  ),
]);

NodeTemplate nodeTemplateById(String id) {
  return defaultNodeTemplates.firstWhere((template) => template.id == id);
}
