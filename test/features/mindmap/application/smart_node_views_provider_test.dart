import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/smart_node_view.dart';

void main() {
  test('smartNodeViewsProvider groups nodes into workspace views', () async {
    final today = DateTime(2026, 6, 18);
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'today-task',
          type: NodeType.task,
          title: 'Today task',
          day: today,
          dueDate: tomorrow,
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'overdue-task',
          type: NodeType.task,
          title: 'Overdue task',
          day: yesterday,
          status: NodeStatus.doing,
          dueDate: yesterday,
          now: DateTime(2026, 6, 18, 9),
        ),
        MindmapNode.create(
          id: 'done-overdue-task',
          type: NodeType.task,
          title: 'Done overdue task',
          day: yesterday,
          isDone: true,
          status: NodeStatus.done,
          dueDate: yesterday,
          now: DateTime(2026, 6, 18, 10),
        ),
        MindmapNode.create(
          id: 'high-task',
          type: NodeType.task,
          title: 'High priority task',
          day: tomorrow,
          priority: NodePriority.high,
          now: DateTime(2026, 6, 18, 11),
        ),
        MindmapNode.create(
          id: 'pinned-note',
          type: NodeType.note,
          title: 'Pinned note',
          day: tomorrow,
          isPinned: true,
          now: DateTime(2026, 6, 18, 12),
        ),
        MindmapNode.create(
          id: 'archived-note',
          type: NodeType.note,
          title: 'Archived note',
          day: tomorrow,
          isArchived: true,
          now: DateTime(2026, 6, 18, 13),
        ),
        MindmapNode.create(
          id: 'linked-note',
          type: NodeType.note,
          title: 'Linked note',
          day: tomorrow,
          relatedNodeIds: const ['today-task'],
          now: DateTime(2026, 6, 18, 14),
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        mindmapRepositoryProvider.overrideWithValue(repository),
        currentDateProvider.overrideWithValue(today),
      ],
    );
    addTearDown(container.dispose);

    final views = await container.read(smartNodeViewsProvider.future);

    expect(
      views.viewFor(SmartNodeViewType.today).nodes.map((node) => node.id),
      ['today-task'],
    );
    expect(
      views.viewFor(SmartNodeViewType.overdue).nodes.map((node) => node.id),
      ['overdue-task'],
    );
    expect(
      views
          .viewFor(SmartNodeViewType.highPriority)
          .nodes
          .map((node) => node.id),
      ['high-task'],
    );
    expect(
      views.viewFor(SmartNodeViewType.pinned).nodes.map((node) => node.id),
      ['pinned-note'],
    );
    expect(
      views.viewFor(SmartNodeViewType.archived).nodes.map((node) => node.id),
      ['archived-note'],
    );
    expect(
      views.viewFor(SmartNodeViewType.linked).nodes.map((node) => node.id),
      ['linked-note'],
    );
  });

  test('smartNodeViewsProvider groups advanced operational views', () async {
    final today = DateTime(2026, 6, 18);
    final yesterday = today.subtract(const Duration(days: 1));
    final dueSoon = today.add(const Duration(days: 3));
    final nextWeek = today.add(const Duration(days: 7));
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'due-soon-task',
          type: NodeType.task,
          title: 'Due soon task',
          day: today,
          status: NodeStatus.doing,
          dueDate: dueSoon,
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'next-week-task',
          type: NodeType.task,
          title: 'Next week task',
          day: today,
          dueDate: nextWeek,
          now: DateTime(2026, 6, 18, 9),
        ),
        MindmapNode.create(
          id: 'overdue-task',
          type: NodeType.task,
          title: 'Overdue task',
          day: yesterday,
          status: NodeStatus.doing,
          dueDate: yesterday,
          now: DateTime(2026, 6, 18, 10),
        ),
        MindmapNode.create(
          id: 'done-upcoming-task',
          type: NodeType.task,
          title: 'Done upcoming task',
          day: today,
          status: NodeStatus.done,
          dueDate: dueSoon,
          now: DateTime(2026, 6, 18, 11),
        ),
        MindmapNode.create(
          id: 'waiting-task',
          type: NodeType.task,
          title: 'Waiting task',
          day: today,
          status: NodeStatus.waiting,
          now: DateTime(2026, 6, 18, 12),
        ),
        MindmapNode.create(
          id: 'routine-plan',
          type: NodeType.plan,
          title: 'Daily plan',
          day: today,
          tags: const ['routine'],
          data: const {
            'automation': {'routineId': 'daily-plan'},
          },
          now: DateTime(2026, 6, 18, 13),
        ),
        MindmapNode.create(
          id: 'weekly-review',
          type: NodeType.journal,
          title: 'Weekly review',
          day: today,
          data: const {
            'journal': {'isWeeklyReview': true},
          },
          now: DateTime(2026, 6, 18, 14),
        ),
        MindmapNode.create(
          id: 'monthly-review',
          type: NodeType.journal,
          title: 'Monthly review',
          day: today,
          data: const {
            'journal': {'isMonthlyReview': true},
          },
          now: DateTime(2026, 6, 18, 15),
        ),
        MindmapNode.create(
          id: 'active-goal',
          type: NodeType.goal,
          title: 'Launch goal',
          day: today,
          status: NodeStatus.doing,
          progress: 0.4,
          now: DateTime(2026, 6, 18, 16),
        ),
        MindmapNode.create(
          id: 'done-goal',
          type: NodeType.goal,
          title: 'Done goal',
          day: today,
          status: NodeStatus.done,
          progress: 1,
          now: DateTime(2026, 6, 18, 17),
        ),
        MindmapNode.create(
          id: 'archived-routine',
          type: NodeType.plan,
          title: 'Archived routine',
          day: today,
          tags: const ['routine'],
          isArchived: true,
          now: DateTime(2026, 6, 18, 18),
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        mindmapRepositoryProvider.overrideWithValue(repository),
        currentDateProvider.overrideWithValue(today),
      ],
    );
    addTearDown(container.dispose);

    final views = await container.read(smartNodeViewsProvider.future);

    expect(
      views.viewFor(SmartNodeViewType.dueSoon).nodes.map((node) => node.id),
      ['due-soon-task', 'next-week-task'],
    );
    expect(
      views.viewFor(SmartNodeViewType.waiting).nodes.map((node) => node.id),
      ['waiting-task'],
    );
    expect(
      views.viewFor(SmartNodeViewType.routines).nodes.map((node) => node.id),
      ['routine-plan'],
    );
    expect(
      views.viewFor(SmartNodeViewType.reviews).nodes.map((node) => node.id),
      ['weekly-review', 'monthly-review'],
    );
    expect(
      views.viewFor(SmartNodeViewType.activeGoals).nodes.map((node) => node.id),
      ['active-goal'],
    );
  });
}
