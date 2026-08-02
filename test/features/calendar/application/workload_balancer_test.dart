import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/workload_balancer.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

MindmapNode task({
  required String id,
  required DateTime day,
  NodePriority priority = NodePriority.low,
}) {
  return MindmapNode.create(
    id: id,
    type: NodeType.task,
    title: id,
    day: day,
    priority: priority,
    now: DateTime(2026, 7, 1, 8, id.hashCode.abs() % 50),
  );
}

void main() {
  test(
    'buildWorkloadBalancePlan spreads low priority work to lighter days',
    () {
      final overloaded = DateTime(2026, 7, 1);
      final light = DateTime(2026, 7, 2);
      final plan = buildWorkloadBalancePlan(
        candidateDays: [overloaded, light, DateTime(2026, 7, 3)],
        overloadThreshold: 3,
        nodes: [
          task(id: 'a', day: overloaded, priority: NodePriority.low),
          task(id: 'b', day: overloaded, priority: NodePriority.low),
          task(id: 'c', day: overloaded, priority: NodePriority.medium),
          task(id: 'd', day: overloaded, priority: NodePriority.high),
        ],
      );

      expect(plan.overloadedDays, contains(overloaded));
      expect(plan.moves, isNotEmpty);
      expect(plan.moves.first.fromDay, overloaded);
      expect(plan.moves.first.toDay, light);
      expect(
        plan.moves.map((move) => move.node.priority),
        isNot(contains(NodePriority.high)),
      );
    },
  );

  test(
    'buildWorkloadBalancePlan ignores someday and inbox nodes in load density & movement',
    () {
      final day = DateTime(2026, 7, 1);
      final light = DateTime(2026, 7, 2);
      final plan = buildWorkloadBalancePlan(
        candidateDays: [day, light],
        overloadThreshold: 2,
        nodes: [
          MindmapNode.create(
            id: 'someday-item',
            type: NodeType.task,
            title: 'Someday task',
            day: day,
            status: NodeStatus.someday,
          ),
          MindmapNode.create(
            id: 'inbox-item',
            type: NodeType.task,
            title: 'Inbox task',
            day: day,
            status: NodeStatus.inbox,
          ),
          task(id: 'open-1', day: day),
        ],
      );

      expect(plan.overloadedDays, isEmpty);
      expect(plan.moves, isEmpty);
    },
  );
}
