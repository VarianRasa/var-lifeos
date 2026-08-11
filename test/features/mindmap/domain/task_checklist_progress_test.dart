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

  test('tree helpers preserve descendants and reject parent cycles', () {
    const items = <TaskChecklistItem>[
      TaskChecklistItem(id: 'a', title: 'Parent'),
      TaskChecklistItem(id: 'b', title: 'Child', parentId: 'a'),
      TaskChecklistItem(id: 'c', title: 'Sibling'),
    ];

    final moved = moveTaskChecklistItem(items, 0, 3);
    expect(moved.map((item) => item.id), <String>['c', 'a', 'b']);
    expect(setTaskChecklistParent(items, 'a', 'b')?.parentId, isNull);
    expect(setTaskChecklistParent(items, 'c', 'a')?.parentId, 'a');
  });

  test('tree normalization clears orphan and cyclic parents', () {
    const items = <TaskChecklistItem>[
      TaskChecklistItem(id: 'a', title: 'A', parentId: 'b'),
      TaskChecklistItem(id: 'b', title: 'B', parentId: 'a'),
      TaskChecklistItem(id: 'c', title: 'C', parentId: 'missing'),
    ];

    final normalized = normalizeTaskChecklistTree(items);
    expect(normalized.every((item) => item.parentId == null), isTrue);
  });

  test('task node load boundary clears malformed checklist parents', () {
    final node = _taskNode(
      checklist: const <TaskChecklistItem>[
        TaskChecklistItem(id: 'a', title: 'A', parentId: 'b'),
        TaskChecklistItem(id: 'b', title: 'B', parentId: 'a'),
        TaskChecklistItem(id: 'c', title: 'C', parentId: 'missing'),
      ],
    );

    expect(node.checklist.every((item) => item.parentId == null), isTrue);
  });

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
