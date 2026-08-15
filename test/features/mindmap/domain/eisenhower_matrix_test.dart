import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/eisenhower_matrix.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  group('Eisenhower Matrix Domain Engine', () {
    final today = DateTime(2026, 8, 7);

    test('categorizes urgent and important node into Q1 Do First', () {
      final node = MindmapNode.create(
        id: 'urgent-high',
        type: NodeType.task,
        title: 'Fix Critical Bug',
        priority: NodePriority.urgent,
        day: today,
        dueDate: today,
      );

      final scored = scoreEisenhowerNode(node, today);
      expect(scored.quadrant, equals(EisenhowerQuadrant.doFirst));
      expect(scored.score, greaterThan(80.0));
    });

    test('categorizes non-urgent important goal into Q2 Schedule', () {
      final node = MindmapNode.create(
        id: 'important-goal',
        type: NodeType.goal,
        title: 'Learn Flutter Advanced',
        priority: NodePriority.high,
        day: today,
      );

      final scored = scoreEisenhowerNode(node, today);
      expect(scored.quadrant, equals(EisenhowerQuadrant.schedule));
    });

    test(
      'EisenhowerMatrixSummary filters done/archived nodes and groups by quadrant',
      () {
        final q1Node = MindmapNode.create(
          id: 'q1',
          type: NodeType.task,
          title: 'Q1 Task',
          priority: NodePriority.urgent,
          dueDate: today,
          day: today,
        );

        final q4Node = MindmapNode.create(
          id: 'q4',
          type: NodeType.note,
          title: 'Casual Note',
          day: today,
        );

        final doneNode = MindmapNode.create(
          id: 'done',
          type: NodeType.task,
          title: 'Done Task',
          isDone: true,
          day: today,
        );

        final summary = EisenhowerMatrixSummary.fromNodes([
          q1Node,
          q4Node,
          doneNode,
        ], today);

        expect(summary.q1DoFirst.length, equals(1));
        expect(summary.q1DoFirst.first.node.id, equals('q1'));
        expect(summary.q4DontDo.length, equals(1));
        expect(summary.q4DontDo.first.node.id, equals('q4'));
      },
    );
  });
}
