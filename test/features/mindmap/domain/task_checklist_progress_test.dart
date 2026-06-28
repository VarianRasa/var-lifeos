import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/task_checklist_progress.dart';

void main() {
  test('nextOpenChecklistItem returns the first unfinished checklist item', () {
    final node = _taskNode(
      checklist: const [
        TaskChecklistItem(id: 'item-1', title: 'Draft copy', isDone: true),
        TaskChecklistItem(id: 'item-2', title: 'Review scope'),
        TaskChecklistItem(id: 'item-3', title: 'Ship update'),
      ],
    );

    expect(nextOpenChecklistItem(node)?.id, 'item-2');
  });

  test(
    'completeNextChecklistItem marks the next item and updates progress',
    () {
      final updatedAt = DateTime(2026, 6, 19, 9);
      final node = _taskNode(
        checklist: const [
          TaskChecklistItem(id: 'item-1', title: 'Draft copy'),
          TaskChecklistItem(id: 'item-2', title: 'Review scope'),
        ],
      );

      final updated = completeNextChecklistItem(node, now: updatedAt);

      expect(updated.checklist[0].isDone, isTrue);
      expect(updated.checklist[1].isDone, isFalse);
      expect(updated.progress, 0.5);
      expect(updated.status, NodeStatus.doing);
      expect(updated.isDone, isFalse);
      expect(updated.updatedAt, updatedAt);
    },
  );

  test(
    'completeNextChecklistItem finishes the task when all items are done',
    () {
      final node = _taskNode(
        checklist: const [
          TaskChecklistItem(id: 'item-1', title: 'Draft copy', isDone: true),
          TaskChecklistItem(id: 'item-2', title: 'Review scope'),
        ],
      );

      final updated = completeNextChecklistItem(
        node,
        now: DateTime(2026, 6, 19, 9),
      );

      expect(updated.checklist.every((item) => item.isDone), isTrue);
      expect(updated.progress, 1);
      expect(updated.status, NodeStatus.done);
      expect(updated.isDone, isTrue);
    },
  );

  test(
    'completeNextChecklistItem leaves non-task or completed nodes unchanged',
    () {
      final completeTask = _taskNode(
        checklist: const [
          TaskChecklistItem(id: 'item-1', title: 'Draft copy', isDone: true),
        ],
      );
      final note = MindmapNode.create(
        id: 'note-1',
        type: NodeType.note,
        title: 'Context',
        day: DateTime(2026, 6, 18),
        now: DateTime(2026, 6, 18, 8),
      );

      expect(completeNextChecklistItem(completeTask), completeTask);
      expect(completeNextChecklistItem(note), note);
    },
  );
}

MindmapNode _taskNode({required List<TaskChecklistItem> checklist}) {
  return MindmapNode.create(
    id: 'task-1',
    type: NodeType.task,
    title: 'Launch task',
    day: DateTime(2026, 6, 18),
    checklist: checklist,
    now: DateTime(2026, 6, 18, 8),
  );
}
