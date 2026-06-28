/// Deterministic demo seed data used only when runtime config enables it.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../domain/canvas_position.dart';
import '../domain/kanban_board.dart';
import '../domain/mindmap_node.dart';

List<MindmapNode> buildSeedMindmapNodes({DateTime? today, DateTime? now}) {
  final day = (today ?? DateTime.now()).dateOnly;
  final timestamp = now ?? DateTime.now();

  return [
    MindmapNode.create(
      id: 'seed-task-plan-day',
      type: NodeType.task,
      title: 'Plan the day',
      body: 'Choose the top three outcomes before adding more nodes.',
      day: day,
      position: const CanvasPosition(-120, -40),
      project: 'Launch App',
      area: 'Work',
      relatedNodeIds: const ['seed-note-context'],
      now: timestamp,
    ),
    MindmapNode.create(
      id: 'seed-note-context',
      type: NodeType.note,
      title: 'Context',
      body: 'Capture loose thoughts here before shaping the mindmap.',
      day: day,
      position: const CanvasPosition(90, -20),
      project: 'Launch App',
      area: 'Work',
      now: timestamp.add(const Duration(minutes: 1)),
    ),
    MindmapNode.create(
      id: 'seed-habit-review',
      type: NodeType.habit,
      title: 'Evening review',
      body: 'Close the day by marking what moved forward.',
      day: day,
      position: const CanvasPosition(0, 110),
      area: 'Health',
      data: {
        'habit': {
          'recurrence': 'daily',
          'target': '10 min',
          'completions': [
            dayKey(day.addDays(-2)),
            dayKey(day.addDays(-1)),
            dayKey(day),
          ],
        },
      },
      now: timestamp.add(const Duration(minutes: 2)),
    ),
    MindmapNode.create(
      id: 'seed-journal-daily',
      type: NodeType.journal,
      title: 'Daily journal',
      body: 'Mood, energy, gratitude, and a short reflection.',
      day: day,
      position: const CanvasPosition(210, 120),
      area: 'Mind',
      data: const {
        'journal': {
          'mood': 4,
          'energy': 3,
          'prompt': 'What mattered today?',
          'gratitude': ['A clear next step'],
          'isWeeklyReview': true,
        },
      },
      now: timestamp.add(const Duration(minutes: 3)),
    ),
    MindmapNode.create(
      id: 'seed-kanban-launch',
      type: NodeType.kanban,
      title: 'Launch board',
      body: 'Move cards as the work changes state.',
      day: day,
      position: const CanvasPosition(-20, -230),
      project: 'Launch App',
      area: 'Work',
      data: {
        'kanban': const KanbanBoard(
          cards: [
            KanbanCard(id: 'seed-card-draft-copy', title: 'Draft copy'),
            KanbanCard(
              id: 'seed-card-review-scope',
              title: 'Review scope',
              column: KanbanColumn.doing,
            ),
            KanbanCard(
              id: 'seed-card-ship-update',
              title: 'Ship update',
              column: KanbanColumn.done,
            ),
          ],
        ).toJson(),
      },
      now: timestamp.add(const Duration(minutes: 4)),
    ),
  ];
}
