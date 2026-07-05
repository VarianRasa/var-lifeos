import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/focus_session.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('markTodayMission toggles mission marker', () {
    final node = MindmapNode.create(
      id: 'task',
      type: NodeType.task,
      title: 'Focus task',
      day: DateTime(2026, 7, 2),
    );

    final marked = markTodayMission(node, isMission: true);
    final unmarked = markTodayMission(marked, isMission: false);

    expect(isTodayMission(marked), isTrue);
    expect(isTodayMission(unmarked), isFalse);
  });

  test('canAddTodayMission enforces default limit', () {
    MindmapNode node(String id, {bool mission = false}) {
      final base = MindmapNode.create(
        id: id,
        type: NodeType.task,
        title: id,
        day: DateTime(2026, 7, 2),
      );
      return mission ? markTodayMission(base, isMission: true) : base;
    }

    final nodes = [
      node('a', mission: true),
      node('b', mission: true),
      node('c', mission: true),
    ];

    expect(canAddTodayMission(nodes, node('d')), isFalse);
    expect(canAddTodayMission(nodes, nodes.first), isTrue);
  });

  test('addFocusSession stores duration and totals minutes', () {
    final node = MindmapNode.create(
      id: 'task',
      type: NodeType.task,
      title: 'Focus task',
      day: DateTime(2026, 7, 2),
    );
    final focused = addFocusSession(
      node,
      startedAt: DateTime(2026, 7, 2, 9),
      endedAt: DateTime(2026, 7, 2, 9, 25),
    );

    expect(focusSessionsForNode(focused), hasLength(1));
    expect(focusSessionsForNode(focused).single.durationMinutes, 25);
    expect(totalFocusMinutes(focused), 25);
  });

  test('nextFocusAction returns first open checklist item', () {
    final node = MindmapNode.create(
      id: 'task',
      type: NodeType.task,
      title: 'Focus task',
      body: '- [x] Done\n- [ ] Draft outline\n- [ ] Ship',
      day: DateTime(2026, 7, 2),
    );

    expect(nextFocusAction(node), 'Draft outline');
  });

  test('nextFocusAction falls back to title', () {
    final node = MindmapNode.create(
      id: 'task',
      type: NodeType.task,
      title: 'Focus task',
      day: DateTime(2026, 7, 2),
    );

    expect(nextFocusAction(node), 'Focus task');
  });

  test('addFocusSession ignores non-positive duration', () {
    final node = MindmapNode.create(
      id: 'task',
      type: NodeType.task,
      title: 'Focus task',
      day: DateTime(2026, 7, 2),
    );

    final unchanged = addFocusSession(
      node,
      startedAt: DateTime(2026, 7, 2, 9),
      endedAt: DateTime(2026, 7, 2, 8),
    );

    expect(unchanged, node);
  });
}
