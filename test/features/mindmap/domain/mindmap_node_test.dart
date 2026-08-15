import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/canvas_position.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('create normalizes the assigned day and timestamps the node', () {
    final now = DateTime(2026, 6, 18, 9, 30);

    final node = MindmapNode.create(
      id: 'node-1',
      type: NodeType.task,
      title: 'Draft project plan',
      day: DateTime(2026, 6, 18, 22, 15),
      now: now,
    );

    expect(node.day, DateTime(2026, 6, 18));
    expect(node.createdAt, now);
    expect(node.updatedAt, now);
  });

  test('serializes to JSON and restores the same domain values', () {
    final node = MindmapNode(
      id: 'node-2',
      type: NodeType.note,
      title: 'Meeting notes',
      body: 'Discuss launch plan',
      day: DateTime(2026, 6, 19),
      position: const CanvasPosition(120, -48),
      createdAt: DateTime(2026, 6, 18, 10),
      updatedAt: DateTime(2026, 6, 18, 11),
      isDone: true,
      status: NodeStatus.doing,
      priority: NodePriority.high,
      project: 'Launch App',
      area: 'Work',
      tags: const ['work', 'launch'],
      dueDate: DateTime(2026, 6, 20, 13),
      progress: 0.65,
      isPinned: true,
      isArchived: true,
      checklist: const [
        TaskChecklistItem(id: 'item-1', title: 'Draft scope', isDone: true),
        TaskChecklistItem(id: 'item-2', title: 'Review launch'),
      ],
      relatedNodeIds: const ['note-1', 'goal-1'],
      data: const {
        'kanban': {
          'cards': [
            {'id': 'card-1', 'title': 'Draft copy', 'column': 'todo'},
          ],
        },
      },
    );

    final restored = MindmapNode.fromJson(node.toJson());

    expect(restored.id, node.id);
    expect(restored.type, node.type);
    expect(restored.title, node.title);
    expect(restored.body, node.body);
    expect(restored.day, node.day);
    expect(restored.position, node.position);
    expect(restored.createdAt, node.createdAt);
    expect(restored.updatedAt, node.updatedAt);
    expect(restored.isDone, isTrue);
    expect(restored.status, NodeStatus.doing);
    expect(restored.priority, NodePriority.high);
    expect(restored.project, 'Launch App');
    expect(restored.area, 'Work');
    expect(restored.tags, ['work', 'launch']);
    expect(restored.dueDate, DateTime(2026, 6, 20));
    expect(restored.progress, 0.65);
    expect(restored.isPinned, isTrue);
    expect(restored.isArchived, isTrue);
    expect(restored.checklist, node.checklist);
    expect(restored.completedChecklistCount, 1);
    expect(restored.checklistProgress, 0.5);
    expect(restored.relatedNodeIds, ['note-1', 'goal-1']);
    expect(restored.data, node.data);
  });

  test('normalizes advanced metadata on create', () {
    final node = MindmapNode.create(
      id: 'task-advanced',
      type: NodeType.task,
      title: 'Launch task',
      day: DateTime(2026, 6, 18),
      tags: const [' Work ', 'work', '#Launch', ''],
      dueDate: DateTime(2026, 6, 19, 18),
      progress: 1.4,
      checklist: const [
        TaskChecklistItem(id: 'item-1', title: 'Draft', isDone: true),
        TaskChecklistItem(id: 'item-2', title: 'Review'),
      ],
      now: DateTime(2026, 6, 18, 9),
    );

    expect(node.tags, ['work', 'launch']);
    expect(node.dueDate, DateTime(2026, 6, 19));
    expect(node.progress, 1);
    expect(node.completedChecklistCount, 1);
    expect(node.checklistProgress, 0.5);
  });

  test('normalizes related node ids on create', () {
    final node = MindmapNode.create(
      id: 'task-1',
      type: NodeType.task,
      title: 'Launch task',
      day: DateTime(2026, 6, 18),
      relatedNodeIds: const [' note-1 ', 'note-1', '', 'task-1', 'goal-1'],
      now: DateTime(2026, 6, 18, 9),
    );

    expect(node.relatedNodeIds, ['note-1', 'goal-1']);
  });

  test('normalizes project and area names on create', () {
    final node = MindmapNode.create(
      id: 'task-context',
      type: NodeType.task,
      title: 'Launch task',
      day: DateTime(2026, 6, 18),
      project: '  Launch   App  ',
      area: '  Work   Ops ',
      now: DateTime(2026, 6, 18, 9),
    );

    expect(node.project, 'Launch App');
    expect(node.area, 'Work Ops');
  });

  test('defensively freezes payload data and node collections', () {
    final nestedList = <Object?>[
      <String, Object?>{'title': 'First'},
    ];
    final source = <String, Object?>{
      'section': <String, Object?>{'items': nestedList},
    };
    final tags = <String>['work'];
    final checklist = <TaskChecklistItem>[
      const TaskChecklistItem(id: 'one', title: 'First'),
    ];
    final node = MindmapNode.create(
      id: 'immutable',
      type: NodeType.task,
      title: 'Immutable',
      day: DateTime(2026, 6, 18),
      tags: tags,
      checklist: checklist,
      data: source,
      now: DateTime(2026, 6, 18, 9),
    );

    source['late'] = true;
    nestedList.add('late');
    tags.add('late');
    checklist.add(const TaskChecklistItem(id: 'two', title: 'Second'));
    expect(node.data.containsKey('late'), isFalse);
    expect(
      ((node.data['section']! as Map<Object?, Object?>)['items']! as List),
      hasLength(1),
    );
    expect(node.tags, ['work']);
    expect(node.checklist, hasLength(1));

    expect(() => node.data['late'] = true, throwsUnsupportedError);
    expect(
      () => (node.data['section']! as Map<Object?, Object?>)['late'] = true,
      throwsUnsupportedError,
    );
    expect(
      () => ((node.data['section']! as Map<Object?, Object?>)['items']! as List)
          .add(<String, Object?>{'title': 'late'}),
      throwsUnsupportedError,
    );
    expect(() => node.tags.add('late'), throwsUnsupportedError);
    expect(
      () => node.checklist.add(
        const TaskChecklistItem(id: 'two', title: 'Second'),
      ),
      throwsUnsupportedError,
    );
  });

  test(
    'presentation revision is stable and changes only with payload data',
    () {
      final node = MindmapNode.create(
        id: 'revision',
        type: NodeType.image,
        title: 'Image',
        day: DateTime(2026, 6, 18),
        data: const {
          'image': {'url': 'https://example.test/a.png'},
        },
        now: DateTime(2026, 6, 18, 9),
      );
      final reconstructed = MindmapNode.fromJson(node.toJson());

      expect(
        reconstructed.presentationDataRevision,
        node.presentationDataRevision,
      );
      expect(reconstructed.presentationDataKey, node.presentationDataKey);
      expect(
        node.copyWith(title: 'Renamed').presentationDataRevision,
        node.presentationDataRevision,
      );
      expect(
        node.copyWith(title: 'Renamed').presentationDataKey,
        node.presentationDataKey,
      );
      expect(
        node
            .copyWith(position: const CanvasPosition(20, 30))
            .presentationDataRevision,
        node.presentationDataRevision,
      );
      expect(
        node
            .copyWith(
              data: const {
                'image': {'url': 'https://example.test/b.png'},
              },
            )
            .presentationDataRevision,
        isNot(node.presentationDataRevision),
      );
      expect(
        node
            .copyWith(
              data: const {
                'image': {'url': 'https://example.test/b.png'},
              },
            )
            .presentationDataKey,
        isNot(node.presentationDataKey),
      );
    },
  );

  test('canonical presentation key supports dates enums and map ordering', () {
    final now = DateTime(2026, 6, 18, 9);
    final first = MindmapNode.create(
      id: 'canonical',
      type: NodeType.note,
      title: 'Canonical',
      day: now,
      data: {
        'date': DateTime(2026, 7, 14, 10, 30),
        'status': NodeStatus.doing,
        'nested': {'b': 2, 'a': 1},
      },
      now: now,
    );
    final reordered = first.copyWith(
      data: {
        'nested': {'a': 1, 'b': 2},
        'status': NodeStatus.doing,
        'date': DateTime(2026, 7, 14, 10, 30),
      },
    );

    expect(reordered.presentationDataKey, first.presentationDataKey);
  });
}
