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
}
