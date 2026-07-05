/// Local-first day setup templates.
library;

import '../../../core/constants/app_constants.dart';
import '../../mindmap/domain/canvas_position.dart';
import '../../mindmap/domain/mindmap_node.dart';

final class DayTemplate {
  const DayTemplate({
    required this.id,
    required this.label,
    required this.description,
    required this.drafts,
  });

  final String id;
  final String label;
  final String description;
  final List<DayTemplateNodeDraft> drafts;
}

final class DayTemplateNodeDraft {
  const DayTemplateNodeDraft({
    required this.type,
    required this.title,
    this.body = '',
    this.priority = NodePriority.none,
    this.tags = const [],
    this.data = const {},
  });

  final NodeType type;
  final String title;
  final String body;
  final NodePriority priority;
  final List<String> tags;
  final Map<String, Object?> data;
}

const List<DayTemplate> dayTemplates = [
  DayTemplate(
    id: 'workday',
    label: 'Workday',
    description: 'Daily work cockpit with top priorities and shutdown review.',
    drafts: [
      DayTemplateNodeDraft(
        type: NodeType.task,
        title: 'Pick top priority',
        priority: NodePriority.high,
        tags: ['template', 'workday'],
      ),
      DayTemplateNodeDraft(
        type: NodeType.plan,
        title: 'Workday plan',
        tags: ['template', 'workday'],
        data: {
          'plan': {
            'steps': ['Triage inbox', 'Deep work block', 'Shutdown review'],
            'completedSteps': <String>[],
          },
        },
      ),
      DayTemplateNodeDraft(
        type: NodeType.journal,
        title: 'Workday shutdown',
        body: 'Wins\n- \n\nOpen loops\n- ',
        tags: ['template', 'workday'],
      ),
    ],
  ),
  DayTemplate(
    id: 'weekend',
    label: 'Weekend',
    description: 'Light reset, errands, and memory capture.',
    drafts: [
      DayTemplateNodeDraft(
        type: NodeType.task,
        title: 'Errands list',
        tags: ['template', 'weekend'],
      ),
      DayTemplateNodeDraft(
        type: NodeType.journal,
        title: 'Weekend memory log',
        tags: ['template', 'weekend'],
      ),
    ],
  ),
  DayTemplate(
    id: 'study-day',
    label: 'Study day',
    description: 'Study plan with notes and recall.',
    drafts: [
      DayTemplateNodeDraft(
        type: NodeType.plan,
        title: 'Study plan',
        priority: NodePriority.high,
        tags: ['template', 'study'],
        data: {
          'plan': {
            'steps': ['Read', 'Practice', 'Recall notes'],
            'completedSteps': <String>[],
          },
        },
      ),
      DayTemplateNodeDraft(
        type: NodeType.note,
        title: 'Study notes',
        tags: ['template', 'study'],
      ),
    ],
  ),
  DayTemplate(
    id: 'weekly-review',
    label: 'Weekly review',
    description: 'Review, learn, and plan next week.',
    drafts: [
      DayTemplateNodeDraft(
        type: NodeType.journal,
        title: 'Weekly review',
        body: 'Highlights\n- \n\nLessons\n- \n\nNext week\n- ',
        tags: ['template', 'weekly-review'],
        data: {
          'journal': {'isWeeklyReview': true},
        },
      ),
    ],
  ),
  DayTemplate(
    id: 'sprint-planning',
    label: 'Sprint planning',
    description: 'Goals, scope, risks, and next actions.',
    drafts: [
      DayTemplateNodeDraft(
        type: NodeType.goal,
        title: 'Sprint goal',
        priority: NodePriority.high,
        tags: ['template', 'sprint'],
      ),
      DayTemplateNodeDraft(
        type: NodeType.kanban,
        title: 'Sprint board',
        tags: ['template', 'sprint'],
      ),
    ],
  ),
  DayTemplate(
    id: 'personal-reset',
    label: 'Personal reset',
    description: 'Health, home, and reflection reset.',
    drafts: [
      DayTemplateNodeDraft(
        type: NodeType.habit,
        title: 'Move body',
        tags: ['template', 'reset'],
      ),
      DayTemplateNodeDraft(
        type: NodeType.task,
        title: 'Clear one small space',
        tags: ['template', 'reset'],
      ),
      DayTemplateNodeDraft(
        type: NodeType.journal,
        title: 'Reset reflection',
        tags: ['template', 'reset'],
      ),
    ],
  ),
];

DayTemplate? dayTemplateById(String id) {
  for (final template in dayTemplates) {
    if (template.id == id) return template;
  }
  return null;
}

bool hasAppliedDayTemplate(List<MindmapNode> nodes, String templateId) {
  return nodes.any(
    (node) =>
        !node.isArchived &&
        node.data['dayTemplateId'] == templateId &&
        node.tags.contains('template'),
  );
}

List<MindmapNode> buildDayTemplateNodes({
  required DayTemplate template,
  required DateTime day,
  required DateTime now,
  required String Function() idFactory,
  List<MindmapNode> existingNodes = const [],
}) {
  if (hasAppliedDayTemplate(existingNodes, template.id)) return const [];

  return List.unmodifiable([
    for (var i = 0; i < template.drafts.length; i += 1)
      MindmapNode.create(
        id: idFactory(),
        type: template.drafts[i].type,
        title: template.drafts[i].title,
        body: template.drafts[i].body,
        day: day,
        priority: template.drafts[i].priority,
        tags: template.drafts[i].tags,
        data: {
          ...template.drafts[i].data,
          'dayTemplateId': template.id,
          'dayTemplateLabel': template.label,
        },
        now: now,
      ).copyWith(position: _templatePosition(i)),
  ]);
}

CanvasPosition _templatePosition(int index) {
  return CanvasPosition((index % 3) * 260.0, (index ~/ 3) * 160.0);
}
