import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/day_node_summary.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  final day = DateTime(2026, 6, 18);

  MindmapNode node({
    required String id,
    required NodeType type,
    String title = 't',
    bool isDone = false,
    NodePriority priority = NodePriority.none,
    DateTime? dueDate,
  }) {
    return MindmapNode.create(
      id: id,
      type: type,
      title: title,
      day: day,
      isDone: isDone,
      priority: priority,
      dueDate: dueDate,
      now: DateTime(2026, 6, 18, 8),
    );
  }

  group('DayNodeSummary', () {
    test('counts nodes by type and totals', () {
      final summary = DayNodeSummary.fromNodes(day, [
        node(id: 'a', type: NodeType.task),
        node(id: 'b', type: NodeType.task),
        node(id: 'c', type: NodeType.note),
      ]);

      expect(summary.totalCount, 3);
      expect(summary.countFor(NodeType.task), 2);
      expect(summary.countFor(NodeType.note), 1);
      expect(summary.hasNodes, isTrue);
    });

    test('splits done and open counts', () {
      final summary = DayNodeSummary.fromNodes(day, [
        node(id: 'a', type: NodeType.task, isDone: true),
        node(id: 'b', type: NodeType.task),
        node(id: 'c', type: NodeType.task),
      ]);

      expect(summary.doneCount, 1);
      expect(summary.openCount, 2);
    });

    test('counts high priority nodes', () {
      final summary = DayNodeSummary.fromNodes(day, [
        node(id: 'a', type: NodeType.task, priority: NodePriority.high),
        node(id: 'b', type: NodeType.task, priority: NodePriority.urgent),
        node(id: 'c', type: NodeType.task, priority: NodePriority.low),
      ]);

      expect(summary.highPriorityCount, 2);
    });

    test('counts overdue nodes due before the day and not done', () {
      final summary = DayNodeSummary.fromNodes(day, [
        node(
          id: 'a',
          type: NodeType.task,
          dueDate: day.subtract(const Duration(days: 1)),
        ),
        node(
          id: 'b',
          type: NodeType.task,
          dueDate: day.subtract(const Duration(days: 2)),
          isDone: true,
        ),
        node(id: 'c', type: NodeType.task, dueDate: day),
      ]);

      expect(summary.overdueCount, 1);
    });

    test('empty nodes produce no counts', () {
      final summary = DayNodeSummary.fromNodes(day, const []);
      expect(summary.hasNodes, isFalse);
      expect(summary.totalCount, 0);
      expect(summary.doneCount, 0);
      expect(summary.openCount, 0);
    });
  });
}
