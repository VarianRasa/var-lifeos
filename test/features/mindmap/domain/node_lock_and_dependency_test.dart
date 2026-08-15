import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  group('MindmapNode Lock & Dependency Tests', () {
    test('isLocked serializes and deserializes correctly', () {
      final node = MindmapNode.create(
        id: 'node-1',
        type: NodeType.note,
        title: 'Secret Note',
        day: DateTime(2026, 8, 8),
        isLocked: true,
      );

      expect(node.isLocked, isTrue);

      final json = node.toJson();
      expect(json['isLocked'], isTrue);

      final deserialized = MindmapNode.fromJson(json);
      expect(deserialized.isLocked, isTrue);
    });

    test('isBlockedBy returns true when blocker is not done', () {
      final blocker = MindmapNode.create(
        id: 'task-blocker',
        type: NodeType.task,
        title: 'Prerequisite Task',
        day: DateTime(2026, 8, 8),
        isDone: false,
        status: NodeStatus.open,
      );

      final dependent = MindmapNode.create(
        id: 'task-dependent',
        type: NodeType.task,
        title: 'Dependent Task',
        day: DateTime(2026, 8, 8),
        blockedByNodeIds: ['task-blocker'],
      );

      expect(dependent.isBlockedBy([blocker, dependent]), isTrue);

      final completedBlocker = blocker.copyWith(
        isDone: true,
        status: NodeStatus.done,
      );
      expect(dependent.isBlockedBy([completedBlocker, dependent]), isFalse);
    });
  });
}
