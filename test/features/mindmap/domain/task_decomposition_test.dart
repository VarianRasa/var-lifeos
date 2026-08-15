import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/task_decomposition.dart';

void main() {
  group('Task Decomposition Engine', () {
    final now = DateTime(2026, 8, 7);

    test('decomposes dev/app task into technical sub-tasks', () {
      final node = MindmapNode.create(
        id: 'task-dev',
        type: NodeType.task,
        title: 'Build Authentication Feature',
        day: now,
      );

      final subTasks = decomposeTask(node);
      expect(subTasks.length, greaterThan(2));
      expect(subTasks.first.title, contains('technical requirements'));
    });

    test('decomposes marketing task into campaign sub-tasks', () {
      final node = MindmapNode.create(
        id: 'task-mkt',
        type: NodeType.task,
        title: 'Launch Product Campaign',
        day: now,
      );

      final subTasks = decomposeTask(node);
      expect(subTasks.length, greaterThan(2));
      expect(subTasks.first.title, contains('target audience'));
    });

    test('fallback generic decomposition for general tasks', () {
      final node = MindmapNode.create(
        id: 'task-gen',
        type: NodeType.task,
        title: 'Organize Storage Closet',
        day: now,
      );

      final subTasks = decomposeTask(node);
      expect(subTasks.length, equals(4));
    });
  });
}
