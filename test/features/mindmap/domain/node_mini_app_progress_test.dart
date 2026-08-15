import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/kanban_board.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_mini_app_progress.dart';

void main() {
  MindmapNode node(NodeType type, {Map<String, Object?> data = const {}}) =>
      MindmapNode.create(
        id: 'node-${type.name}',
        type: type,
        title: type.label,
        day: DateTime(2026, 8, 11),
        data: data,
      );

  test('synchronizes task completion from checklist', () {
    final source = node(NodeType.task).copyWith(
      checklist: const <TaskChecklistItem>[
        TaskChecklistItem(id: 'a', title: 'A', isDone: true),
        TaskChecklistItem(id: 'b', title: 'B', isDone: true),
      ],
    );

    final result = synchronizeNodeMiniAppProgress(source);
    expect(result.progress, 1);
    expect(result.isDone, isTrue);
    expect(result.status, NodeStatus.done);
  });

  test('synchronizes kanban progress from done columns', () {
    const board = KanbanBoard(
      cards: <KanbanCard>[
        KanbanCard(id: 'a', title: 'A', column: KanbanColumn.done),
        KanbanCard(id: 'b', title: 'B', column: KanbanColumn.todo),
      ],
    );
    final source = node(
      NodeType.kanban,
      data: <String, Object?>{'kanban': board.toJson()},
    );

    final result = synchronizeNodeMiniAppProgress(source);
    expect(result.progress, 0.5);
    expect(result.isDone, isFalse);
  });
}
